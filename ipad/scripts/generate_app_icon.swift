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
        color(0x071014),
        color(0x10262C),
        color(0x142E35)
    ] as CFArray
    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: backgroundColors, locations: [0, 0.62, 1])!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 80, y: 980),
        end: CGPoint(x: 930, y: 60),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    context.setFillColor(color(0x5FE1D0, alpha: 0.10))
    context.saveGState()
    context.translateBy(x: 0, y: 120)
    context.rotate(by: -0.36)
    context.fill(CGRect(x: -120, y: 435, width: 1280, height: 92))
    context.restoreGState()

    let panel = CGRect(x: 166, y: 194, width: 692, height: 636)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -28), blur: 48, color: color(0x000000, alpha: 0.34))
    context.addPath(CGPath(roundedRect: panel, cornerWidth: 116, cornerHeight: 116, transform: nil))
    context.setFillColor(color(0x182E34))
    context.fillPath()
    context.restoreGState()

    context.addPath(CGPath(roundedRect: panel.insetBy(dx: 8, dy: 8), cornerWidth: 104, cornerHeight: 104, transform: nil))
    context.setStrokeColor(color(0x7FD7CC, alpha: 0.22))
    context.setLineWidth(12)
    context.strokePath()

    let topBar = CGRect(x: 220, y: 716, width: 584, height: 64)
    context.addPath(CGPath(roundedRect: topBar, cornerWidth: 32, cornerHeight: 32, transform: nil))
    context.setFillColor(color(0x0D1C21, alpha: 0.74))
    context.fillPath()

    for index in 0..<3 {
        context.addEllipse(in: CGRect(x: 256 + index * 46, y: 738, width: 18, height: 18))
        context.setFillColor(color(index == 0 ? 0xFF5C7A : index == 1 ? 0xFFD166 : 0x8DF0DF))
        context.fillPath()
    }

    context.setStrokeColor(color(0xA8FFF2, alpha: 0.94))
    context.setLineWidth(58)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    let mark = CGMutablePath()
    mark.move(to: CGPoint(x: 314, y: 326))
    mark.addLine(to: CGPoint(x: 512, y: 682))
    mark.addLine(to: CGPoint(x: 710, y: 326))
    context.addPath(mark)
    context.strokePath()

    context.setStrokeColor(color(0xB8F277, alpha: 0.96))
    context.setLineWidth(46)
    let crossbar = CGMutablePath()
    crossbar.move(to: CGPoint(x: 420, y: 474))
    crossbar.addLine(to: CGPoint(x: 604, y: 474))
    context.addPath(crossbar)
    context.strokePath()

    context.setStrokeColor(color(0x7FD7CC, alpha: 0.90))
    context.setLineWidth(34)
    let leftChevron = CGMutablePath()
    leftChevron.move(to: CGPoint(x: 292, y: 568))
    leftChevron.addLine(to: CGPoint(x: 238, y: 512))
    leftChevron.addLine(to: CGPoint(x: 292, y: 456))
    context.addPath(leftChevron)
    context.strokePath()

    let rightChevron = CGMutablePath()
    rightChevron.move(to: CGPoint(x: 732, y: 568))
    rightChevron.addLine(to: CGPoint(x: 786, y: 512))
    rightChevron.addLine(to: CGPoint(x: 732, y: 456))
    context.addPath(rightChevron)
    context.strokePath()

    context.setStrokeColor(color(0x5FE1D0, alpha: 0.42))
    context.setLineWidth(22)
    let orbit = CGMutablePath()
    orbit.move(to: CGPoint(x: 642, y: 650))
    orbit.addCurve(to: CGPoint(x: 768, y: 648), control1: CGPoint(x: 682, y: 716), control2: CGPoint(x: 736, y: 716))
    context.addPath(orbit)
    context.strokePath()

    context.setFillColor(color(0xB8F277))
    context.addEllipse(in: CGRect(x: 770, y: 626, width: 48, height: 48))
    context.fillPath()

    let terminal = CGRect(x: 248, y: 260, width: 528, height: 72)
    context.addPath(CGPath(roundedRect: terminal, cornerWidth: 36, cornerHeight: 36, transform: nil))
    context.setFillColor(color(0x091418, alpha: 0.78))
    context.fillPath()

    context.setStrokeColor(color(0x8DF0DF, alpha: 0.90))
    context.setLineWidth(18)
    context.setLineCap(.round)
    let prompt = CGMutablePath()
    prompt.move(to: CGPoint(x: 296, y: 298))
    prompt.addLine(to: CGPoint(x: 342, y: 298))
    prompt.move(to: CGPoint(x: 386, y: 298))
    prompt.addLine(to: CGPoint(x: 566, y: 298))
    context.addPath(prompt)
    context.strokePath()

    guard let image = context.makeImage() else {
        fatalError("Could not render icon")
    }
    return image
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
