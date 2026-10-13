import SwiftUI

/// A row of one-tap category circles. Tapping the selected one again clears it so Dumpling decides.
struct CategoryButtons: View {
    @Binding var selection: CategoryKind?

    var body: some View {
        HStack {
            ForEach(CategoryKind.allCases) { kind in
                CategoryButton(kind: kind, isSelected: selection == kind) {
                    selection = selection == kind ? nil : kind
                }
                if kind != CategoryKind.allCases.last { Spacer(minLength: 0) }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CategoryButton: View {
    let kind: CategoryKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: kind.systemImage)
                .font(.title3)
                .foregroundStyle(isSelected ? .white : kind.tint)
                .frame(width: 40, height: 40)
                .background(isSelected ? kind.tint : kind.tint.opacity(0.15), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
