#!/usr/bin/env swift
import AppKit
import Foundation

// macOS .iconset required sizes
let iconSizes: [(String, Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

/// Build the play-triangle CGPath from the SVG in research/AppIcon.icon.
/// SVG viewBox: 0 0 170.42 190.23.  Rendered at `scale` fraction of `canvasSize`,
/// centered with a slight leftward nudge matching the Icon Composer translation.
func makeTrianglePath(canvasSize s: CGFloat) -> CGPath {
    let svgW: CGFloat = 170.42
    let svgH: CGFloat = 190.23

    // Match Icon Composer: scale 3 inside ~1024 → ~55% of canvas height
    let targetH = s * 0.55
    let sc = targetH / svgH
    let triW = svgW * sc
    let triH = svgH * sc
    // Slight left offset (Icon Composer: -29pt at scale 3 in 1024 ≈ 2.8%)
    let ox = (s - triW) / 2 - s * 0.028
    let oy = (s - triH) / 2

    // SVG is Y-down, CG is Y-up → flip
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * sc + ox, y: s - (y * sc + oy))
    }

    let p = CGMutablePath()
    p.move(to: pt(10.7, 113.64))
    p.addLine(to: pt(138.33, 187.33))
    p.addCurve(to: pt(170.42, 168.80),
               control1: pt(152.59, 195.57), control2: pt(170.42, 185.27))
    p.addLine(to: pt(170.42, 21.43))
    p.addCurve(to: pt(138.33, 2.90),
               control1: pt(170.42, 4.96), control2: pt(152.59, -5.33))
    p.addLine(to: pt(10.7, 76.58))
    p.addCurve(to: pt(10.7, 113.64),
               control1: pt(-3.56, 84.82), control2: pt(-3.56, 105.40))
    p.closeSubpath()
    return p
}

/// Render one icon PNG at the given pixel size.
func renderIcon(
    size: Int,
    drawBackground: (CGContext, CGFloat) -> Void,
    fgColor: CGColor,
    fgAlpha: CGFloat
) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = NSGraphicsContext.current!.cgContext

    drawBackground(cg, s)

    // Subtle drop shadow behind triangle
    cg.setShadow(
        offset: CGSize(width: 0, height: -s * 0.012),
        blur: s * 0.025,
        color: CGColor(gray: 0, alpha: 0.35)
    )

    let path = makeTrianglePath(canvasSize: s)
    cg.setAlpha(fgAlpha)
    cg.setFillColor(fgColor)
    cg.addPath(path)
    cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// Build an .iconset directory and convert to .icns via iconutil.
func createIcns(
    name: String,
    dir: String,
    drawBg: @escaping (CGContext, CGFloat) -> Void,
    fgColor: CGColor,
    fgAlpha: CGFloat
) {
    let iconsetDir = "\(dir)/\(name).iconset"
    let fm = FileManager.default
    try? fm.removeItem(atPath: iconsetDir)
    try! fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

    for (sizeName, size) in iconSizes {
        let data = renderIcon(size: size, drawBackground: drawBg, fgColor: fgColor, fgAlpha: fgAlpha)
        try! data.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(sizeName).png"))
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    proc.arguments = ["-c", "icns", iconsetDir, "-o", "\(dir)/\(name).icns"]
    try! proc.run()
    proc.waitUntilExit()
    try? fm.removeItem(atPath: iconsetDir)

    if proc.terminationStatus == 0 {
        print("Created \(dir)/\(name).icns")
    } else {
        fputs("FAILED: \(name).icns\n", stderr)
        exit(1)
    }
}

/// Render the play triangle as a template image for the menu bar.
/// Template images are black shape on transparent background; macOS handles light/dark.
/// Menu bar icons are 18pt tall (36px @2x).
func renderMenuBarIcon(height: Int) -> Data {
    let svgW: CGFloat = 170.42
    let svgH: CGFloat = 190.23
    let h = CGFloat(height)
    // Scale SVG to fill the height with a little padding
    let padding = h * 0.1
    let sc = (h - padding * 2) / svgH
    let w = ceil(svgW * sc + padding * 2)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = NSGraphicsContext.current!.cgContext

    // Transparent background — only draw the triangle in black
    let ox = (w - svgW * sc) / 2
    let oy = padding

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * sc + ox, y: h - (y * sc + oy))
    }

    let p = CGMutablePath()
    p.move(to: pt(10.7, 113.64))
    p.addLine(to: pt(138.33, 187.33))
    p.addCurve(to: pt(170.42, 168.80),
               control1: pt(152.59, 195.57), control2: pt(170.42, 185.27))
    p.addLine(to: pt(170.42, 21.43))
    p.addCurve(to: pt(138.33, 2.90),
               control1: pt(170.42, 4.96), control2: pt(152.59, -5.33))
    p.addLine(to: pt(10.7, 76.58))
    p.addCurve(to: pt(10.7, 113.64),
               control1: pt(-3.56, 84.82), control2: pt(-3.56, 105.40))
    p.closeSubpath()

    cg.setFillColor(CGColor(gray: 0, alpha: 1.0))
    cg.addPath(p)
    cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// ─── Main ───

let repoRoot = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let outDir = "\(repoRoot)/app/resources"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let cs = CGColorSpaceCreateDeviceRGB()

// Production: cyan-to-blue gradient background, white triangle at 50% opacity
createIcns(name: "AppIcon", dir: outDir, drawBg: { ctx, s in
    let colors = [
        CGColor(colorSpace: cs, components: [0.0, 0.75294, 0.90980, 1.0])!,
        CGColor(colorSpace: cs, components: [0.0, 0.53333, 1.0, 1.0])!,
    ] as CFArray
    let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.0, 1.0])!
    // Gradient from top (y=s) to 30% from bottom (y=0.3*s), matching Icon Composer orientation
    ctx.drawLinearGradient(grad,
        start: CGPoint(x: s / 2, y: s),
        end: CGPoint(x: s / 2, y: s * 0.3),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}, fgColor: CGColor(gray: 1.0, alpha: 1.0), fgAlpha: 0.5)

// Dev: red solid background, orange triangle at 50% opacity
createIcns(name: "AppIconDev", dir: outDir, drawBg: { ctx, s in
    ctx.setFillColor(CGColor(colorSpace: cs, components: [0.96783, 0.24142, 0.19769, 1.0])!)
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
}, fgColor: CGColor(colorSpace: cs, components: [0.97025, 0.58398, 0.38475, 1.0])!, fgAlpha: 0.5)

// Menu bar template image: black triangle on transparent, 18pt (@1x) and 36px (@2x)
let mb1x = renderMenuBarIcon(height: 18)
let mb2x = renderMenuBarIcon(height: 36)
try! mb1x.write(to: URL(fileURLWithPath: "\(outDir)/MenuBarIcon.png"))
try! mb2x.write(to: URL(fileURLWithPath: "\(outDir)/MenuBarIcon@2x.png"))
print("Created \(outDir)/MenuBarIcon.png and MenuBarIcon@2x.png")

print("Done!")
