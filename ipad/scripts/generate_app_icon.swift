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
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)

    context.setFillColor(color(0x0F171A))
    context.fill(canvas)

    let editor = CGRect(x: 74, y: 82, width: 876, height: 860)
    context.addPath(CGPath(roundedRect: editor, cornerWidth: 132, cornerHeight: 132, transform: nil))
    context.setFillColor(color(0x263238))
    context.fillPath()

    context.addPath(CGPath(roundedRect: editor.insetBy(dx: 9, dy: 9), cornerWidth: 120, cornerHeight: 120, transform: nil))
    context.setStrokeColor(color(0x31454B))
    context.setLineWidth(18)
    context.strokePath()

    for index in 0..<3 {
        context.addEllipse(in: CGRect(x: 158 + index * 46, y: 826, width: 22, height: 22))
        context.setFillColor(color(index == 0 ? 0xFF5370 : index == 1 ? 0xFFCB6B : 0x80CBC4))
        context.fillPath()
    }

    context.setStrokeColor(color(0x89DDFF, alpha: 0.98))
    context.setLineWidth(66)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    let leftChevron = CGMutablePath()
    leftChevron.move(to: CGPoint(x: 300, y: 632))
    leftChevron.addLine(to: CGPoint(x: 198, y: 512))
    leftChevron.addLine(to: CGPoint(x: 300, y: 392))
    context.addPath(leftChevron)
    context.strokePath()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: color(0xEEFFFF, alpha: 0.22))
    drawCentralCloud(in: context, fill: color(0xEEFFFF))
    context.restoreGState()

    context.setStrokeColor(color(0xC3E88D, alpha: 0.98))
    context.setLineWidth(52)
    context.setLineCap(.round)
    let slash = CGMutablePath()
    slash.move(to: CGPoint(x: 698, y: 392))
    slash.addLine(to: CGPoint(x: 754, y: 632))
    context.addPath(slash)
    context.strokePath()

    context.setStrokeColor(color(0x89DDFF, alpha: 0.98))
    context.setLineWidth(66)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let rightChevron = CGMutablePath()
    rightChevron.move(to: CGPoint(x: 784, y: 632))
    rightChevron.addLine(to: CGPoint(x: 886, y: 512))
    rightChevron.addLine(to: CGPoint(x: 784, y: 392))
    context.addPath(rightChevron)
    context.strokePath()

    guard let image = context.makeImage() else {
        fatalError("Could not render icon")
    }
    return image
}

func drawCentralCloud(in context: CGContext, fill: CGColor) {
    context.setFillColor(fill)
    context.fillEllipse(in: CGRect(x: 350, y: 470, width: 142, height: 128))
    context.fillEllipse(in: CGRect(x: 450, y: 526, width: 158, height: 158))
    context.fillEllipse(in: CGRect(x: 558, y: 474, width: 126, height: 120))
    context.addPath(CGPath(roundedRect: CGRect(x: 360, y: 444, width: 306, height: 128), cornerWidth: 64, cornerHeight: 64, transform: nil))
    context.fillPath()

    context.setFillColor(color(0xFFFFFF, alpha: 0.36))
    context.fillEllipse(in: CGRect(x: 392, y: 516, width: 82, height: 68))
    context.fillEllipse(in: CGRect(x: 512, y: 578, width: 72, height: 64))
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
