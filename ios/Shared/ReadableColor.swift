import SwiftUI
import UIKit

extension Color {
    /// A color with its own shade for light and dark mode, as 0xRRGGBB. Light-mode shades are deeper than the
    /// system colors, which are too pale on white (yellow is 1.5:1, green and orange 2.2:1).
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// One shade in both modes, as 0xRRGGBB.
    init(rgb: UInt32) {
        self.init(uiColor: UIColor(rgb: rgb))
    }

    /// Warnings in text, like "Couldn't file": orange that reads on white.
    static let warning = Color(light: 0xC93400, dark: 0xFF9F0A)
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// White or black for text and symbols on a colored background, whichever reads: white unless it falls under
/// 3:1 (the bar for bold text this size), as on bright yellow, green or orange.
struct ReadableOn: ShapeStyle {
    let background: Color

    func resolve(in environment: EnvironmentValues) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: environment.colorScheme == .dark ? .dark : .light)
        let resolved = UIColor(background).resolvedColor(with: traits)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .white }
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        let whiteContrast = 1.05 / (luminance + 0.05)
        return whiteContrast >= 3 ? .white : .black
    }
}

extension ShapeStyle where Self == ReadableOn {
    /// White or black, whichever reads on `background`.
    static func readable(on background: Color) -> ReadableOn { ReadableOn(background: background) }
}
