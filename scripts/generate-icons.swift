import AppKit

struct IconSlot {
    let idiom: String
    let size: String
    let scale: String
    let filename: String
    let pixels: Int
    let role: String?
    let subtype: String?
}

let slots: [IconSlot] = [
    .init(idiom: "iphone", size: "20x20", scale: "2x", filename: "AppIcon-iphone-20@2x.png", pixels: 40, role: nil, subtype: nil),
    .init(idiom: "iphone", size: "20x20", scale: "3x", filename: "AppIcon-iphone-20@3x.png", pixels: 60, role: nil, subtype: nil),
    .init(idiom: "iphone", size: "29x29", scale: "2x", filename: "AppIcon-iphone-29@2x.png", pixels: 58, role: nil, subtype: nil),
    .init(idiom: "iphone", size: "29x29", scale: "3x", filename: "AppIcon-iphone-29@3x.png", pixels: 87, role: nil, subtype: nil),
    .init(idiom: "iphone", size: "40x40", scale: "2x", filename: "AppIcon-iphone-40@2x.png", pixels: 80, role: nil, subtype: nil),
    .init(idiom: "iphone", size: "40x40", scale: "3x", filename: "AppIcon-iphone-40@3x.png", pixels: 120, role: nil, subtype: nil),
    .init(idiom: "iphone", size: "60x60", scale: "2x", filename: "AppIcon-iphone-60@2x.png", pixels: 120, role: nil, subtype: nil),
    .init(idiom: "iphone", size: "60x60", scale: "3x", filename: "AppIcon-iphone-60@3x.png", pixels: 180, role: nil, subtype: nil),
    .init(idiom: "ipad", size: "20x20", scale: "1x", filename: "AppIcon-ipad-20@1x.png", pixels: 20, role: nil, subtype: nil),
    .init(idiom: "ipad", size: "20x20", scale: "2x", filename: "AppIcon-ipad-20@2x.png", pixels: 40, role: nil, subtype: nil),
    .init(idiom: "ipad", size: "29x29", scale: "1x", filename: "AppIcon-ipad-29@1x.png", pixels: 29, role: nil, subtype: nil),
    .init(idiom: "ipad", size: "29x29", scale: "2x", filename: "AppIcon-ipad-29@2x.png", pixels: 58, role: nil, subtype: nil),
    .init(idiom: "ipad", size: "40x40", scale: "1x", filename: "AppIcon-ipad-40@1x.png", pixels: 40, role: nil, subtype: nil),
    .init(idiom: "ipad", size: "40x40", scale: "2x", filename: "AppIcon-ipad-40@2x.png", pixels: 80, role: nil, subtype: nil),
    .init(idiom: "ipad", size: "76x76", scale: "2x", filename: "AppIcon-ipad-76@2x.png", pixels: 152, role: nil, subtype: nil),
    .init(idiom: "ipad", size: "83.5x83.5", scale: "2x", filename: "AppIcon-ipad-83.5@2x.png", pixels: 167, role: nil, subtype: nil),
    .init(idiom: "ios-marketing", size: "1024x1024", scale: "1x", filename: "AppIcon-ios-marketing-1024.png", pixels: 1024, role: nil, subtype: nil),
    .init(idiom: "mac", size: "16x16", scale: "1x", filename: "AppIcon-mac-16@1x.png", pixels: 16, role: nil, subtype: nil),
    .init(idiom: "mac", size: "16x16", scale: "2x", filename: "AppIcon-mac-16@2x.png", pixels: 32, role: nil, subtype: nil),
    .init(idiom: "mac", size: "32x32", scale: "1x", filename: "AppIcon-mac-32@1x.png", pixels: 32, role: nil, subtype: nil),
    .init(idiom: "mac", size: "32x32", scale: "2x", filename: "AppIcon-mac-32@2x.png", pixels: 64, role: nil, subtype: nil),
    .init(idiom: "mac", size: "128x128", scale: "1x", filename: "AppIcon-mac-128@1x.png", pixels: 128, role: nil, subtype: nil),
    .init(idiom: "mac", size: "128x128", scale: "2x", filename: "AppIcon-mac-128@2x.png", pixels: 256, role: nil, subtype: nil),
    .init(idiom: "mac", size: "256x256", scale: "1x", filename: "AppIcon-mac-256@1x.png", pixels: 256, role: nil, subtype: nil),
    .init(idiom: "mac", size: "256x256", scale: "2x", filename: "AppIcon-mac-256@2x.png", pixels: 512, role: nil, subtype: nil),
    .init(idiom: "mac", size: "512x512", scale: "1x", filename: "AppIcon-mac-512@1x.png", pixels: 512, role: nil, subtype: nil),
    .init(idiom: "mac", size: "512x512", scale: "2x", filename: "AppIcon-mac-512@2x.png", pixels: 1024, role: nil, subtype: nil),
    .init(idiom: "car", size: "60x60", scale: "2x", filename: "AppIcon-car-60@2x.png", pixels: 120, role: nil, subtype: nil),
    .init(idiom: "car", size: "60x60", scale: "3x", filename: "AppIcon-car-60@3x.png", pixels: 180, role: nil, subtype: nil)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawIcon(size: Int, url: URL) throws {
    let scale = CGFloat(size) / 1024
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "IconExport", code: 1)
    }

    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.current = previousContext }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    color(9, 12, 17).setFill()
    rect.fill()

    let background = NSGradient(colors: [
        color(9, 12, 17),
        color(18, 32, 42),
        color(12, 19, 29)
    ])!
    background.draw(in: rect, angle: 135)

    let glow = NSBezierPath(ovalIn: NSRect(x: 124 * scale, y: 118 * scale, width: 776 * scale, height: 776 * scale))
    color(67, 221, 207, 0.18).setFill()
    glow.fill()

    let cone = NSBezierPath()
    cone.move(to: NSPoint(x: 278 * scale, y: 272 * scale))
    cone.line(to: NSPoint(x: 778 * scale, y: 512 * scale))
    cone.line(to: NSPoint(x: 278 * scale, y: 752 * scale))
    cone.close()
    color(239, 246, 255, 0.96).setFill()
    cone.fill()

    let innerCone = NSBezierPath()
    innerCone.move(to: NSPoint(x: 368 * scale, y: 420 * scale))
    innerCone.line(to: NSPoint(x: 598 * scale, y: 512 * scale))
    innerCone.line(to: NSPoint(x: 368 * scale, y: 604 * scale))
    innerCone.close()
    color(24, 31, 41, 0.92).setFill()
    innerCone.fill()

    let aperture = NSBezierPath(ovalIn: NSRect(x: 228 * scale, y: 392 * scale, width: 236 * scale, height: 240 * scale))
    color(80, 235, 211).setFill()
    aperture.fill()

    let core = NSBezierPath(ovalIn: NSRect(x: 292 * scale, y: 456 * scale, width: 108 * scale, height: 112 * scale))
    color(14, 18, 24).setFill()
    core.fill()

    for (index, alpha) in [0.92, 0.56, 0.28].enumerated() {
        let inset = CGFloat(index) * 86 * scale
        let waveRect = NSRect(x: (492 * scale) + inset, y: (292 * scale) + inset / 2, width: (314 * scale) - inset / 1.4, height: (440 * scale) - inset)
        let wave = NSBezierPath()
        wave.appendArc(withCenter: NSPoint(x: waveRect.minX, y: waveRect.midY), radius: waveRect.height / 2, startAngle: -54, endAngle: 54, clockwise: false)
        wave.lineWidth = max(7 * scale, 1)
        color(80, 235, 211, alpha).setStroke()
        wave.stroke()
    }

    if size >= 128 {
        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: 278 * scale, y: 752 * scale))
        highlight.line(to: NSPoint(x: 778 * scale, y: 512 * scale))
        color(255, 255, 255, 0.22).setStroke()
        highlight.lineWidth = max(12 * scale, 1)
        highlight.stroke()
    }

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconExport", code: 2)
    }
    try png.write(to: url)
}

func contentsJSON() throws -> Data {
    let images = slots.map { slot -> [String: String] in
        var item = [
            "idiom": slot.idiom,
            "size": slot.size,
            "scale": slot.scale,
            "filename": slot.filename
        ]
        if let role = slot.role {
            item["role"] = role
        }
        if let subtype = slot.subtype {
            item["subtype"] = subtype
        }
        return item
    }
    let payload: [String: Any] = [
        "images": images,
        "info": [
            "author": "xcode",
            "version": 1
        ]
    ]
    return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
}

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIconURL = repoRoot.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: appIconURL, withIntermediateDirectories: true)

for slot in slots {
    try drawIcon(size: slot.pixels, url: appIconURL.appendingPathComponent(slot.filename))
}

try contentsJSON().write(to: appIconURL.appendingPathComponent("Contents.json"))
print("Generated \(slots.count) app icon files in \(appIconURL.path)")
