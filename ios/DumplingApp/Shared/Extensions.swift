import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Design tokens

extension Color {
    static let dPink     = Color(hex: "FFB3C6")
    static let dBlue     = Color(hex: "B3D9FF")
    static let dMint     = Color(hex: "B3FFD9")
    static let dLavender = Color(hex: "D9B3FF")
    static let dButter   = Color(hex: "FFF3B3")
    static let dCream    = Color(hex: "FAFAF0")
    static let dBlack    = Color(hex: "1A1A1A")
}

// MARK: - Pixel style modifiers

extension View {
    func pixelBorder(_ color: Color = .dBlack, width: CGFloat = 2) -> some View {
        self.overlay(Rectangle().stroke(color, lineWidth: width))
    }

    func pixelShadow(_ offset: CGFloat = 3) -> some View {
        self.shadow(color: .dBlack, radius: 0, x: offset, y: offset)
    }

    func pixelCard(background: Color = .dCream) -> some View {
        self
            .background(background)
            .pixelBorder(width: 2)
            .pixelShadow(3)
    }
}
