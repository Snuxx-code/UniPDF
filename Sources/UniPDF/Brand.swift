import SwiftUI
import UniPDFCore

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
/// Its path is BrandMark's (UniPDFCore), which the study PDF's footer draws too; scripts/make-icon.swift
/// draws the same paths for the app icon.
struct BrandSymbol: Shape {
    var small = false

    func path(in rect: CGRect) -> Path {
        // SwiftUI's y already points down, as in the SVG.
        let scale = min(rect.width, rect.height) / 256
        return Path(BrandMark.path(small: small))
            .applying(CGAffineTransform(translationX: rect.midX - 128 * scale, y: rect.midY - 128 * scale).scaledBy(x: scale, y: scale))
    }
}
