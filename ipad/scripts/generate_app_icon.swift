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
        color(0x06141B),
        color(0x0B2B38),
        color(0x123F52)
    ] as CFArray
    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: backgroundColors, locations: [0, 0.58, 1])!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 96, y: 968),
        end: CGPoint(x: 928, y: 96),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    let topBar = CGRect(x: 76, y: 792, width: 872, height: 116)
    context.addPath(CGPath(roundedRect: topBar, cornerWidth: 42, cornerHeight: 42, transform: nil))
    context.setFillColor(color(0x08222E, alpha: 0.86))
    context.fillPath()

    for index in 0..<3 {
        context.addEllipse(in: CGRect(x: 128 + index * 48, y: 837, width: 22, height: 22))
        context.setFillColor(color(index == 0 ? 0xFF6B8A : index == 1 ? 0xFFD36E : 0x8DF0DF))
        context.fillPath()
    }

    context.setFillColor(color(0x123F52, alpha: 0.72))
    context.addPath(CGPath(roundedRect: CGRect(x: 302, y: 830, width: 354, height: 36), cornerWidth: 18, cornerHeight: 18, transform: nil))
    context.fillPath()
    context.setFillColor(color(0x1A5367, alpha: 0.58))
    context.addPath(CGPath(roundedRect: CGRect(x: 684, y: 830, width: 184, height: 36), cornerWidth: 18, cornerHeight: 18, transform: nil))
    context.fillPath()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: color(0x6BD2FF, alpha: 0.22))
    drawCentralCloud(in: context, fill: color(0x8ED8FF))
    context.restoreGState()

    context.setStrokeColor(color(0xD1FFF9, alpha: 0.98))
    context.setLineWidth(56)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    let leftChevron = CGMutablePath()
    leftChevron.move(to: CGPoint(x: 322, y: 606))
    leftChevron.addLine(to: CGPoint(x: 230, y: 512))
    leftChevron.addLine(to: CGPoint(x: 322, y: 418))
    context.addPath(leftChevron)
    context.strokePath()

    context.setStrokeColor(color(0xB9F77E, alpha: 0.98))
    context.setLineWidth(46)
    let slash = CGMutablePath()
    slash.move(to: CGPoint(x: 660, y: 404))
    slash.addLine(to: CGPoint(x: 716, y: 620))
    context.addPath(slash)
    context.strokePath()

    context.setStrokeColor(color(0xD1FFF9, alpha: 0.98))
    context.setLineWidth(56)
    let rightChevron = CGMutablePath()
    rightChevron.move(to: CGPoint(x: 744, y: 606))
    rightChevron.addLine(to: CGPoint(x: 836, y: 512))
    rightChevron.addLine(to: CGPoint(x: 744, y: 418))
    context.addPath(rightChevron)
    context.strokePath()

    guard let image = context.makeImage() else {
        fatalError("Could not render icon")
    }
    return image
}

func drawCentralCloud(in context: CGContext, fill: CGColor) {
    context.setFillColor(fill)
    context.fillEllipse(in: CGRect(x: 394, y: 468, width: 138, height: 120))
    context.fillEllipse(in: CGRect(x: 492, y: 520, width: 152, height: 152))
    context.fillEllipse(in: CGRect(x: 600, y: 470, width: 124, height: 116))
    context.addPath(CGPath(roundedRect: CGRect(x: 408, y: 446, width: 290, height: 124), cornerWidth: 62, cornerHeight: 62, transform: nil))
    context.fillPath()

    context.setFillColor(color(0xCFF4FF, alpha: 0.46))
    context.fillEllipse(in: CGRect(x: 440, y: 514, width: 78, height: 64))
    context.fillEllipse(in: CGRect(x: 552, y: 574, width: 70, height: 64))
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
