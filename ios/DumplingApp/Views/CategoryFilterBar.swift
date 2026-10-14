import SwiftUI

/// Mail-style filter row: the selected category expands to show its name; nil means All.
struct CategoryFilterBar: View {
    @Binding var selection: CategoryKind?
    let available: [CategoryKind]
    var overMap = false

    /// Shared with the Select mode action bar so switching between them doesn't move anything.
    static let chipHeight: CGFloat = 36
    static let topPadding: CGFloat = 6
    /// Room above the tab bar so a reach for a filter doesn't land on a tab.
    static let bottomPadding: CGFloat = 24

    @State private var chipFrames: [String: CGRect] = [:]

    var body: some View {
        // The selected pill stretches so the row spans the screen; with too many categories to fit, it scrolls.
        ViewThatFits(in: .horizontal) {
            chips(stretchSelected: true)
                .coordinateSpace(.named("filterChips"))
                // Slide a finger along the row to switch filters. Starts after a few points of movement,
                // so plain taps still go to the buttons.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named("filterChips"))
                        .onChanged { drag in
                            guard let key = chipFrames.first(where: { $0.value.contains(drag.location) })?.key else { return }
                            let kind = CategoryKind(rawValue: key)
                            if kind != selection { selection = kind }
                        }
                )
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                chips(stretchSelected: false)
                    .padding(.horizontal, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, Self.topPadding)
        .padding(.bottom, Self.bottomPadding)
        .mapFrost(overMap)
        .animation(.snappy(duration: 0.2), value: selection)
        .animation(.easeInOut(duration: 0.25), value: overMap)
    }

    private func chips(stretchSelected: Bool) -> some View {
        GlassEffectContainer(spacing: 5) {
            HStack(spacing: 5) {
                chip(nil, label: "All", systemImage: "square.stack", tint: .accentColor, stretch: stretchSelected)
                ForEach(available) { kind in
                    chip(kind, label: kind.label, systemImage: kind.systemImage, tint: kind.tint, stretch: stretchSelected)
                }
            }
        }
    }

    private func chip(_ kind: CategoryKind?, label: String, systemImage: String, tint: Color, stretch: Bool) -> some View {
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
            .padding(.horizontal, isSelected ? 12 : 0)
            .frame(minWidth: Self.chipHeight, maxWidth: isSelected && stretch ? .infinity : nil, minHeight: Self.chipHeight)
            // Glass, so the chips stay readable over cards (or the map) scrolling beneath them.
            .glassEffect(isSelected ? .regular.tint(tint) : .regular, in: .capsule)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("filterChips")) } action: { frame in
            if stretch { chipFrames[kind?.rawValue ?? "all"] = frame }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
