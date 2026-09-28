#!/usr/bin/env swift
// Renders the CleanCut app icon (1024×1024) with Core Graphics so the icon is
// reproducible from source: a product "lifted" onto a clean studio floor.
//
//   swift Tools/scripts/make-app-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// Deep teal background with a soft top light.
let background = CGGradient(colorsSpace: space, colors: [color(0x14A394), color(0x0B5E57)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: CGFloat(size)), end: .zero, options: [])

// Studio floor: a light rounded card.
let card = CGRect(x: 172, y: 172, width: 680, height: 680)
ctx.addPath(CGPath(roundedRect: card, cornerWidth: 120, cornerHeight: 120, transform: nil))
ctx.setFillColor(color(0xF7F7F5))
ctx.fillPath()

// Contact shadow.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 36, color: color(0x000000, 0.35))
ctx.setFillColor(color(0x000000, 0.22))
ctx.fillEllipse(in: CGRect(x: 332, y: 282, width: 360, height: 52))
ctx.restoreGState()

// The "product": a bottle-like silhouette in the accent color.
let product = CGMutablePath()
product.addRoundedRect(in: CGRect(x: 382, y: 300, width: 260, height: 330), cornerWidth: 64, cornerHeight: 64)
product.addRoundedRect(in: CGRect(x: 462, y: 610, width: 100, height: 120), cornerWidth: 28, cornerHeight: 28)
product.addRoundedRect(in: CGRect(x: 446, y: 716, width: 132, height: 44), cornerWidth: 16, cornerHeight: 16)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0x000000, 0.25))
ctx.addPath(product)
ctx.setFillColor(color(0x0F766E))
ctx.fillPath()
ctx.restoreGState()

// Highlight on the product.
ctx.addPath(CGPath(roundedRect: CGRect(x: 418, y: 360, width: 44, height: 210), cornerWidth: 22, cornerHeight: 22, transform: nil))
ctx.setFillColor(color(0xFFFFFF, 0.28))
ctx.fillPath()

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: output)
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(output)") }
print("Wrote \(output)")
