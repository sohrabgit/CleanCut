#!/usr/bin/env swift
// Renders the CleanCut app icon and launch-screen logo with Core Graphics so
// both are reproducible from source and always match: a product lifted off a
// full-bleed teal field, traced by a cut-out selection line.
//
// The icon is full-bleed on purpose. An inner card with its own rounded
// corners fights the system's icon mask and reads as an icon inside an icon.
//
//   swift Tools/scripts/make-app-icon.swift App/Resources/Assets.xcassets
//
// writes AppIcon.appiconset/AppIcon.png and LaunchLogo.imageset/LaunchLogo@{2,3}x.png.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let catalog = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "App/Resources/Assets.xcassets")
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

/// A four-point sparkle: the "done for you" moment.
func sparkle(at c: CGPoint, radius r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let waist = r * 0.18
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + waist, y: c.y + waist))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + waist, y: c.y - waist))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - waist, y: c.y - waist))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - waist, y: c.y + waist))
    p.closeSubpath()
    return p
}

/// The accent teal, lit from the top left like a studio sweep.
func drawBackground(in ctx: CGContext, size: Int) {
    ctx.drawLinearGradient(
        gradient([color(0x1FB5A3), color(0x0F766E), color(0x0A4F4A)], [0, 0.55, 1]),
        start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: []
    )
    ctx.drawRadialGradient(
        gradient([color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)], [0, 1]),
        startCenter: CGPoint(x: 512, y: 640), startRadius: 0,
        endCenter: CGPoint(x: 512, y: 640), endRadius: 520, options: []
    )
}

/// The bottle, its cut-out line and sparkles, in the icon's 1024-point space.
/// `SplashView.Sparkle` redraws the sparkles in SwiftUI from these same numbers.
func drawMark(in ctx: CGContext, sparkles: Bool = true) {
    // The product: a serum bottle with curved shoulders, centred and a touch high so
    // the contact shadow has room below it.
    let centerX: CGFloat = 488
    let bodyWidth: CGFloat = 300, bodyBottom: CGFloat = 238, shoulderY: CGFloat = 580
    let neckWidth: CGFloat = 124, neckTop: CGFloat = 700
    let capWidth: CGFloat = 176, capTop: CGFloat = 822

    let body = CGMutablePath()
    let left = centerX - bodyWidth / 2, right = centerX + bodyWidth / 2
    let neckLeft = centerX - neckWidth / 2, neckRight = centerX + neckWidth / 2
    let corner: CGFloat = 64
    body.move(to: CGPoint(x: left, y: bodyBottom + corner))
    body.addQuadCurve(to: CGPoint(x: left + corner, y: bodyBottom), control: CGPoint(x: left, y: bodyBottom))
    body.addLine(to: CGPoint(x: right - corner, y: bodyBottom))
    body.addQuadCurve(to: CGPoint(x: right, y: bodyBottom + corner), control: CGPoint(x: right, y: bodyBottom))
    body.addLine(to: CGPoint(x: right, y: shoulderY))
    body.addCurve(
        to: CGPoint(x: neckRight, y: neckTop - 20),
        control1: CGPoint(x: right, y: shoulderY + 90), control2: CGPoint(x: neckRight + 40, y: neckTop - 20)
    )
    body.addLine(to: CGPoint(x: neckRight, y: neckTop))
    body.addLine(to: CGPoint(x: neckLeft, y: neckTop))
    body.addLine(to: CGPoint(x: neckLeft, y: neckTop - 20))
    body.addCurve(
        to: CGPoint(x: left, y: shoulderY),
        control1: CGPoint(x: neckLeft - 40, y: neckTop - 20), control2: CGPoint(x: left, y: shoulderY + 90)
    )
    body.closeSubpath()

    let cap = CGPath(
        roundedRect: CGRect(x: centerX - capWidth / 2, y: neckTop - 8, width: capWidth, height: capTop - neckTop + 8),
        cornerWidth: 30, cornerHeight: 30, transform: nil
    )
    let silhouette = body.union(cap)

    // Cut-out selection: a dotted line offset evenly around the whole silhouette.
    // Unioning the silhouette with its own thick stroke leaves only the outer contour.
    let outline = silhouette.union(silhouette.copy(strokingWithWidth: 88, lineCap: .round, lineJoin: .round, miterLimit: 10))
    ctx.saveGState()
    ctx.addPath(outline)
    ctx.setLineWidth(13)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [0, 30])
    ctx.setStrokeColor(color(0xFFFFFF, 0.9))
    ctx.strokePath()
    ctx.restoreGState()

    // Contact shadow on the floor.
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: centerX - 190, y: bodyBottom - 34, width: 380, height: 60))
    ctx.clip()
    ctx.drawRadialGradient(
        gradient([color(0x032E2A, 0.55), color(0x032E2A, 0)], [0, 1]),
        startCenter: CGPoint(x: centerX, y: bodyBottom - 4), startRadius: 0,
        endCenter: CGPoint(x: centerX, y: bodyBottom - 4), endRadius: 190, options: []
    )
    ctx.restoreGState()

    // Body: soft white with a gentle side-to-side shading so it reads as a solid.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 48, color: color(0x02302B, 0.35))
    ctx.addPath(body)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([color(0xFFFFFF), color(0xF3FAF9), color(0xD5E9E6)], [0, 0.5, 1]),
        start: CGPoint(x: left, y: 0), end: CGPoint(x: right, y: 0), options: []
    )
    // Label band in the accent colour.
    ctx.setFillColor(color(0x0F766E))
    ctx.fill(CGRect(x: left, y: 360, width: bodyWidth, height: 128))
    ctx.setFillColor(color(0xFFFFFF, 0.9))
    ctx.addPath(CGPath(roundedRect: CGRect(x: centerX - 70, y: 416, width: 140, height: 16), cornerWidth: 8, cornerHeight: 8, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()

    // Cap: dark teal, with a thin top highlight.
    ctx.saveGState()
    ctx.addPath(cap)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([color(0x0E6B63), color(0x0A4F4A), color(0x063A36)], [0, 0.5, 1]),
        start: CGPoint(x: centerX - capWidth / 2, y: 0), end: CGPoint(x: centerX + capWidth / 2, y: 0), options: []
    )
    ctx.setFillColor(color(0xFFFFFF, 0.18))
    ctx.fill(CGRect(x: centerX - capWidth / 2 + 26, y: neckTop + 14, width: 18, height: capTop - neckTop - 40))
    ctx.restoreGState()

    guard sparkles else { return }
    ctx.setFillColor(color(0xFFFFFF))
    ctx.addPath(sparkle(at: CGPoint(x: 742, y: 790), radius: 70))
    ctx.fillPath()
    ctx.setFillColor(color(0xFFFFFF, 0.75))
    ctx.addPath(sparkle(at: CGPoint(x: 820, y: 680), radius: 32))
    ctx.fillPath()
}

func render(pixels: Int, opaque: Bool, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
    )!
    draw(ctx)
    return ctx.makeImage()!
}

func write(_ image: CGImage, to relativePath: String) {
    let url = catalog.appendingPathComponent(relativePath)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
    print("Wrote \(url.path)")
}

write(render(pixels: 1024, opaque: true) { ctx in
    drawBackground(in: ctx, size: 1024)
    drawMark(in: ctx)
}, to: "AppIcon.appiconset/AppIcon.png")

// The launch logo is the mark alone on transparency, cropped to a square
// centred on the bottle so it sits dead centre on the solid launch colour.
// 200 pt, which `SplashView` must match so the hand-off doesn't jump.
// LaunchProduct is the same crop without the sparkles, which `SplashView`
// draws itself so it can animate them.
let launchCrop = CGRect(x: 488 - 380, y: 530 - 380, width: 760, height: 760)
for (name, sparkles) in [("LaunchLogo", true), ("LaunchProduct", false)] {
    for scale in [2, 3] {
        let pixels = 200 * scale
        write(render(pixels: pixels, opaque: false) { ctx in
            ctx.scaleBy(x: CGFloat(pixels) / launchCrop.width, y: CGFloat(pixels) / launchCrop.height)
            ctx.translateBy(x: -launchCrop.minX, y: -launchCrop.minY)
            drawMark(in: ctx, sparkles: sparkles)
        }, to: "\(name).imageset/\(name)@\(scale)x.png")
    }
}
