import SwiftUI

/// Mail-style filter row: the selected category expands to show its name; nil means All.
struct CategoryFilterBar: View {
    @Binding var selection: CategoryKind?
    let available: [CategoryKind]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, label: "All", systemImage: "square.stack", tint: .accentColor)
                ForEach(available) { kind in
                    chip(kind, label: kind.label, systemImage: kind.systemImage, tint: kind.tint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Fade cards out beneath the bar so the chips don't sit on top of them.
        .background {
            LinearGradient(stops: [.init(color: Color(.systemGroupedBackground).opacity(0), location: 0),
                                   .init(color: Color(.systemGroupedBackground), location: 0.45)],
                           startPoint: .top, endPoint: .bottom)
                .padding(.top, -16)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.snappy(duration: 0.2), value: selection)
    }

    private func chip(_ kind: CategoryKind?, label: String, systemImage: String, tint: Color) -> some View {
        let isSelected = selection == kind
        return Button {
            selection = kind
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                if isSelected {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize()
                }
            }
            .foregroundStyle(isSelected ? .white : tint)
            .padding(.horizontal, isSelected ? 14 : 0)
            .frame(minWidth: 38, minHeight: 38)
            .background(isSelected ? tint : tint.opacity(0.15), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
