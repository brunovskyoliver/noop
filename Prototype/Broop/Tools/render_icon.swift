// Renders the 1024×1024 Broop app icon: a white "B" on a near-black gradient.
// The polygons mirror BrandMark in Sources/Components.swift (100×100 grid).
// Usage: swift Tools/render_icon.swift Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import CoreGraphics
import Foundation
import ImageIO

let outer: [(CGFloat, CGFloat)] = [(24, 14), (62, 14), (74, 26), (74, 40), (67, 49), (78, 60), (78, 74), (66, 86), (24, 86)]
let upper: [(CGFloat, CGFloat)] = [(40, 28), (56, 28), (58, 30), (58, 38), (54, 42), (40, 42)]
let lower: [(CGFloat, CGFloat)] = [(40, 56), (58, 56), (62, 60), (62, 69), (59, 72), (40, 72)]

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// Background: a subtle top-to-bottom gradient so the icon isn't a flat black square.
let gradient = CGGradient(colorsSpace: space, colors: [
    CGColor(srgbRed: 0.10, green: 0.11, blue: 0.12, alpha: 1),
    CGColor(srgbRed: 0.015, green: 0.02, blue: 0.02, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

// Map the 100-unit grid (y down) into the canvas (y up), centred on (51, 50).
let scale = CGFloat(size) * 0.60 / 72
func point(_ p: (CGFloat, CGFloat)) -> CGPoint {
    CGPoint(x: CGFloat(size) / 2 + (p.0 - 51) * scale, y: CGFloat(size) / 2 - (p.1 - 50) * scale)
}
let path = CGMutablePath()
for poly in [outer, upper, lower] {
    path.addLines(between: poly.map(point))
    path.closeSubpath()
}
ctx.addPath(path)
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.fillPath(using: .evenOdd)

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote \(url.path)")
