import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        NSColor(srgbRed: 0.16, green: 0.17, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 45, y: 45, width: 934, height: 934), xRadius: 208, yRadius: 208).fill()
        let ring = NSBezierPath()
        ring.appendArc(
            withCenter: NSPoint(x: 512, y: 512), radius: 265, startAngle: 80, endAngle: 370, clockwise: false)
        ring.lineWidth = 39
        ring.lineCapStyle = .round
        NSColor(srgbRed: 0.94, green: 0.49, blue: 0.36, alpha: 1).setStroke()
        ring.stroke()
        let hands = NSBezierPath()
        hands.move(to: NSPoint(x: 512, y: 694))
        hands.line(to: NSPoint(x: 512, y: 512))
        hands.line(to: NSPoint(x: 644, y: 434))
        hands.lineWidth = 42
        hands.lineCapStyle = .round
        hands.lineJoinStyle = .round
        NSColor(srgbRed: 0.96, green: 0.95, blue: 0.93, alpha: 1).setStroke()
        hands.stroke()
        NSColor(srgbRed: 0.94, green: 0.49, blue: 0.36, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 414, y: 741, width: 40, height: 40)).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
