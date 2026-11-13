import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Native-size renditions of the chosen pause mark. Draw from geometry so each
// size has a sharp silhouette and the menu bar can apply its own foreground.
func render(size: Int, appIcon: Bool, at url: URL) throws {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }
    let scale = CGFloat(size) / 100
    context.scaleBy(x: scale, y: scale)

    if appIcon {
        let tile = CGPath(
            roundedRect: CGRect(x: 10, y: 10, width: 80, height: 80),
            cornerWidth: 18, cornerHeight: 18, transform: nil
        )
        context.addPath(tile)
        context.setFillColor(red: 18.0 / 255, green: 21.0 / 255, blue: 20.0 / 255, alpha: 1)
        context.fillPath()
        context.translateBy(x: 18, y: 18)
        context.scaleBy(x: 0.64, y: 0.64)
        context.setFillColor(red: 201.0 / 255, green: 227.0 / 255, blue: 122.0 / 255, alpha: 1)
        context.setStrokeColor(red: 201.0 / 255, green: 227.0 / 255, blue: 122.0 / 255, alpha: 1)
    } else {
        context.setFillColor(gray: 0, alpha: 1)
        context.setStrokeColor(gray: 0, alpha: 1)
    }

    context.setLineWidth(10)
    context.addArc(center: CGPoint(x: 50, y: 50), radius: 41,
                   startAngle: .pi * 0.32, endAngle: .pi * 2.22, clockwise: false)
    context.strokePath()

    for x in [34.0, 54.0] {
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: 31, width: 12, height: 38),
                               cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
        context.fillPath()
    }

    guard let image = context.makeImage(),
          let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(writer, image, nil)
    guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = output.appending(path: "SlowVape.iconset", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let suffix = density == 2 ? "@2x" : ""
        try render(size: size * density, appIcon: true,
                   at: iconset.appending(path: "icon_\(size)x\(size)\(suffix).png"))
    }
}
try render(size: 64, appIcon: false, at: output.appending(path: "BrandMark.png"))
