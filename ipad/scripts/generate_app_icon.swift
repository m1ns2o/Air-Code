#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

struct IconSlot {
    let filename: String
    let pixels: Int
}

let slots = [
    IconSlot(filename: "AppIcon-20@1x.png", pixels: 20),
    IconSlot(filename: "AppIcon-20@2x.png", pixels: 40),
    IconSlot(filename: "AppIcon-29@1x.png", pixels: 29),
    IconSlot(filename: "AppIcon-29@2x.png", pixels: 58),
    IconSlot(filename: "AppIcon-40@1x.png", pixels: 40),
    IconSlot(filename: "AppIcon-40@2x.png", pixels: 80),
    IconSlot(filename: "AppIcon-76@2x.png", pixels: 152),
    IconSlot(filename: "AppIcon-83.5@2x.png", pixels: 167),
    IconSlot(filename: "AppIcon-1024@1x.png", pixels: 1024)
]

let outputPath = CommandLine.arguments.dropFirst().first ?? "ipad/App/Assets.xcassets/AppIcon.appiconset"
let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

func makeContext(width: Int, height: Int) -> CGContext {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create bitmap context")
    }
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    return context
}

func drawMasterIcon() -> CGImage {
    let size = 1024
    let context = makeContext(width: size, height: size)

    let backgroundColors = [
        color(0xFFFFFF),
        color(0xF4FBFF),
        color(0xEAF7FF)
    ] as CFArray
    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: backgroundColors, locations: [0, 0.58, 1])!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 160, y: 980),
        end: CGPoint(x: 900, y: 80),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -22), blur: 36, color: color(0x71BFEF, alpha: 0.28))
    drawCloud(in: context, fill: color(0x8ED8FF))
    context.restoreGState()

    context.saveGState()
    context.setAlpha(0.34)
    context.setFillColor(color(0xDFF5FF))
    context.fillEllipse(in: CGRect(x: 690, y: 654, width: 116, height: 116))
    context.fillEllipse(in: CGRect(x: 202, y: 620, width: 84, height: 84))
    context.fillEllipse(in: CGRect(x: 792, y: 302, width: 58, height: 58))
    context.restoreGState()

    let editor = CGRect(x: 214, y: 256, width: 596, height: 468)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -20), blur: 36, color: color(0x164D70, alpha: 0.26))
    context.addPath(CGPath(roundedRect: editor, cornerWidth: 58, cornerHeight: 58, transform: nil))
    context.setFillColor(color(0x113342))
    context.fillPath()
    context.restoreGState()

    let topBar = CGRect(x: 248, y: 636, width: 528, height: 56)
    context.addPath(CGPath(roundedRect: topBar, cornerWidth: 32, cornerHeight: 32, transform: nil))
    context.setFillColor(color(0x082532, alpha: 0.82))
    context.fillPath()

    for index in 0..<3 {
        context.addEllipse(in: CGRect(x: 282 + index * 42, y: 656, width: 18, height: 18))
        context.setFillColor(color(index == 0 ? 0xFF6B8A : index == 1 ? 0xFFD36E : 0x7BE9DC))
        context.fillPath()
    }

    context.setStrokeColor(color(0xC8FFF7, alpha: 0.98))
    context.setLineWidth(48)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    let leftChevron = CGMutablePath()
    leftChevron.move(to: CGPoint(x: 372, y: 554))
    leftChevron.addLine(to: CGPoint(x: 312, y: 494))
    leftChevron.addLine(to: CGPoint(x: 372, y: 434))
    context.addPath(leftChevron)
    context.strokePath()

    let rightChevron = CGMutablePath()
    rightChevron.move(to: CGPoint(x: 652, y: 554))
    rightChevron.addLine(to: CGPoint(x: 712, y: 494))
    rightChevron.addLine(to: CGPoint(x: 652, y: 434))
    context.addPath(rightChevron)
    context.strokePath()

    context.setStrokeColor(color(0xBAF37B, alpha: 0.98))
    context.setLineWidth(38)
    context.setLineCap(.round)
    let slash = CGMutablePath()
    slash.move(to: CGPoint(x: 548, y: 572))
    slash.addLine(to: CGPoint(x: 476, y: 416))
    context.addPath(slash)
    context.strokePath()

    let codeLineRects = [
        CGRect(x: 314, y: 374, width: 182, height: 22),
        CGRect(x: 532, y: 374, width: 166, height: 22),
        CGRect(x: 314, y: 332, width: 316, height: 22)
    ]
    context.setFillColor(color(0x7FDBD2, alpha: 0.82))
    for rect in codeLineRects {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 11, cornerHeight: 11, transform: nil))
        context.fillPath()
    }

    context.setFillColor(color(0xBAF37B, alpha: 0.90))
    context.addPath(CGPath(roundedRect: CGRect(x: 648, y: 332, width: 62, height: 22), cornerWidth: 11, cornerHeight: 11, transform: nil))
    context.fillPath()

    let terminal = CGRect(x: 274, y: 284, width: 476, height: 56)
    context.addPath(CGPath(roundedRect: terminal, cornerWidth: 36, cornerHeight: 36, transform: nil))
    context.setFillColor(color(0x061C27, alpha: 0.80))
    context.fillPath()

    context.setStrokeColor(color(0xD5FFF8, alpha: 0.94))
    context.setLineWidth(14)
    context.setLineCap(.round)
    let prompt = CGMutablePath()
    prompt.move(to: CGPoint(x: 318, y: 312))
    prompt.addLine(to: CGPoint(x: 356, y: 312))
    prompt.move(to: CGPoint(x: 394, y: 312))
    prompt.addLine(to: CGPoint(x: 568, y: 312))
    context.addPath(prompt)
    context.strokePath()

    context.setFillColor(color(0xFFFFFF, alpha: 0.88))
    context.addEllipse(in: CGRect(x: 720, y: 700, width: 54, height: 54))
    context.fillPath()
    context.setFillColor(color(0x67C7FF, alpha: 0.96))
    context.addEllipse(in: CGRect(x: 737, y: 716, width: 20, height: 20))
    context.fillPath()

    guard let image = context.makeImage() else {
        fatalError("Could not render icon")
    }
    return image
}

func drawCloud(in context: CGContext, fill: CGColor) {
    context.setFillColor(fill)
    context.fillEllipse(in: CGRect(x: 126, y: 340, width: 294, height: 270))
    context.fillEllipse(in: CGRect(x: 284, y: 544, width: 260, height: 232))
    context.fillEllipse(in: CGRect(x: 430, y: 618, width: 246, height: 250))
    context.fillEllipse(in: CGRect(x: 612, y: 532, width: 268, height: 240))
    context.fillEllipse(in: CGRect(x: 708, y: 340, width: 220, height: 230))
    context.addPath(CGPath(roundedRect: CGRect(x: 172, y: 332, width: 686, height: 292), cornerWidth: 146, cornerHeight: 146, transform: nil))
    context.fillPath()

    context.setFillColor(color(0xBDEBFF, alpha: 0.54))
    context.fillEllipse(in: CGRect(x: 250, y: 518, width: 160, height: 128))
    context.fillEllipse(in: CGRect(x: 498, y: 690, width: 118, height: 108))
    context.fillEllipse(in: CGRect(x: 650, y: 522, width: 142, height: 118))
}

func resizedPNG(from image: CGImage, pixels: Int) -> Data {
    let context = makeContext(width: pixels, height: pixels)
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    guard let scaled = context.makeImage() else {
        fatalError("Could not resize icon")
    }
    let rep = NSBitmapImageRep(cgImage: scaled)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG")
    }
    return data
}

let master = drawMasterIcon()
for slot in slots {
    let url = outputURL.appendingPathComponent(slot.filename)
    try resizedPNG(from: master, pixels: slot.pixels).write(to: url, options: .atomic)
    print("wrote \(url.path)")
}
