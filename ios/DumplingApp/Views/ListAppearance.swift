import SwiftUI

/// List colors, like Reminders.
enum ListColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown
    var id: Self { self }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        }
    }
}

extension ItemList {
    var listColor: ListColor { colorName.flatMap(ListColor.init(rawValue:)) ?? .teal }
    var symbol: String { symbolName ?? ListSymbols.defaultSymbol }
}

/// A list's icon: its symbol in white on a circle of its color, like Reminders.
struct ListIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28

    init(list: ItemList, size: CGFloat = 28) {
        self.symbol = list.symbol
        self.color = list.listColor.color
        self.size = size
    }

    init(symbol: String, color: Color, size: CGFloat = 28) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: .circle)
            .accessibilityHidden(true)
    }
}
