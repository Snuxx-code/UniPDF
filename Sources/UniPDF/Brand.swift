import SwiftUI

/// The brand of UniPDF, shared with the web app: its symbol and the gradient from green to blue.
/// The gradient is an accent only, on the few marks that stand out; text, surfaces and most controls
/// keep the quiet study green.
enum Brand {
    static let gradient = LinearGradient(stops: [
        .init(color: Color(red: 0x1E / 255, green: 0x6B / 255, blue: 0x52 / 255), location: 0),
        .init(color: Color(red: 0x22 / 255, green: 0xA3 / 255, blue: 0x8A / 255), location: 0.52),
        .init(color: Color(red: 0x3D / 255, green: 0x86 / 255, blue: 0xF0 / 255), location: 1)
    ], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// The UniPDF symbol, a page whose frame opens on the right where the text marker passes through.
/// Drawn from the web app's brand kit (public/brand/unipdf-symbol.svg, and the bolder -small cut for
/// sizes below about 32 points); scripts/make-icon.swift draws the same paths for the app icon.
struct BrandSymbol: Shape {
    var small = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = small ? 16 : 22, right: CGFloat = small ? 179 : 185, opening: CGFloat = small ? 100 : 102
        let top: CGFloat = small ? 64 : 58, bottom: CGFloat = small ? 192 : 198, left: CGFloat = small ? 43 : 37
        let k: CGFloat = 0.5523 // Control points of a quarter circle.
        path.move(to: CGPoint(x: right, y: 148))
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addCurve(to: CGPoint(x: right - radius, y: bottom), control1: CGPoint(x: right, y: bottom - radius + radius * k),
                      control2: CGPoint(x: right - radius + radius * k, y: bottom))
        path.addLine(to: CGPoint(x: 59, y: bottom))
        path.addCurve(to: CGPoint(x: left, y: bottom - radius), control1: CGPoint(x: 59 - radius * k, y: bottom),
                      control2: CGPoint(x: left, y: bottom - radius * k))
        path.addLine(to: CGPoint(x: left, y: 80))
        path.addCurve(to: CGPoint(x: 59, y: top), control1: CGPoint(x: left, y: 80 - radius * k), control2: CGPoint(x: 59 - radius * k, y: top))
        path.addLine(to: CGPoint(x: 163, y: top))
        path.addCurve(to: CGPoint(x: right, y: 80), control1: CGPoint(x: 163 + radius * k, y: top), control2: CGPoint(x: right, y: 80 - radius * k))
        path.addLine(to: CGPoint(x: right, y: opening))
        path.addLine(to: CGPoint(x: 203, y: opening))
        path.addLine(to: CGPoint(x: 203, y: 80))
        path.addCurve(to: CGPoint(x: 163, y: 40), control1: CGPoint(x: 203, y: 57.9), control2: CGPoint(x: 185.1, y: 40))
        path.addLine(to: CGPoint(x: 59, y: 40))
        path.addCurve(to: CGPoint(x: 19, y: 80), control1: CGPoint(x: 36.9, y: 40), control2: CGPoint(x: 19, y: 57.9))
        path.addLine(to: CGPoint(x: 19, y: 176))
        path.addCurve(to: CGPoint(x: 59, y: 216), control1: CGPoint(x: 19, y: 198.1), control2: CGPoint(x: 36.9, y: 216))
        path.addLine(to: CGPoint(x: 163, y: 216))
        path.addCurve(to: CGPoint(x: 203, y: 176), control1: CGPoint(x: 185.1, y: 216), control2: CGPoint(x: 203, y: 198.1))
        path.addLine(to: CGPoint(x: 203, y: 148))
        path.closeSubpath()
        let lines = small ? [CGRect(x: 59, y: 80, width: 68, height: 16), CGRect(x: 59, y: 160, width: 84, height: 16)]
            : [CGRect(x: 59, y: 80, width: 48, height: 12), CGRect(x: 115, y: 80, width: 40, height: 12), CGRect(x: 59, y: 158, width: 76, height: 12)]
        for line in lines { path.addRoundedRect(in: line, cornerSize: CGSize(width: line.height / 2, height: line.height / 2)) }
        let markerTop: CGFloat = small ? 104 : 108, height: CGFloat = small ? 40 : 32, slant: CGFloat = small ? 10.72 : 8.57
        path.move(to: CGPoint(x: 67, y: markerTop))
        path.addLine(to: CGPoint(x: 237, y: markerTop))
        path.addLine(to: CGPoint(x: 237 - slant, y: markerTop + height))
        path.addLine(to: CGPoint(x: 67, y: markerTop + height))
        path.addArc(center: CGPoint(x: 67, y: markerTop + height / 2), radius: height / 2,
                    startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        // SwiftUI's y already points down, as in the SVG.
        let scale = min(rect.width, rect.height) / 256
        return path.applying(CGAffineTransform(translationX: rect.midX - 128 * scale, y: rect.midY - 128 * scale).scaledBy(x: scale, y: scale))
    }
}
