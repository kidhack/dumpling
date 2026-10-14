import SwiftUI

/// Mail-style filter row: the selected category expands to show its name; nil means All.
struct CategoryFilterBar: View {
    @Binding var selection: CategoryKind?
    let available: [CategoryKind]
    /// Map/list toggle, shown as a button above the Location pill while that filter is on.
    var showingMap: Binding<Bool>?

    /// Shared with the Select mode action bar so switching between them doesn't move anything.
    static let chipHeight: CGFloat = 36
    static let topPadding: CGFloat = 6
    /// Room above the tab bar so a reach for a filter doesn't land on a tab.
    static let bottomPadding: CGFloat = 24

    static let mapButtonSize: CGFloat = 44
    /// How far the map button reaches above the bar, for anything stacked over it.
    static let mapButtonClearance: CGFloat = mapButtonSize + 8

    @State private var chipFrames: [String: CGRect] = [:]
    @State private var scrollingChipFrames: [String: CGRect] = [:]
    /// Center of the Location pill's icon in each layout, keyed by whether the pill stretches.
    @State private var locationIconX: [Bool: CGFloat] = [:]

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
                    .coordinateSpace(.named("filterChips"))
                    .padding(.horizontal, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The map button sits above the row, outside the scroll view's bounds.
            .scrollClipDisabled()
        }
        .padding(.top, Self.topPadding)
        .padding(.bottom, Self.bottomPadding)
        // Fade cards out beneath the bar so the chips don't sit on top of them.
        .bottomBarFade()
        .animation(.snappy(duration: 0.2), value: selection)
    }

    private func chips(stretchSelected: Bool) -> some View {
        HStack(spacing: 5) {
            chip(nil, label: "All", systemImage: "square.stack", tint: .accentColor, stretch: stretchSelected)
            ForEach(available) { kind in
                chip(kind, label: kind.label, systemImage: kind.systemImage, tint: kind.tint, stretch: stretchSelected)
            }
        }
        .overlay(alignment: .topLeading) {
            let frames = stretchSelected ? chipFrames : scrollingChipFrames
            if selection == .location, let showingMap, let pill = frames[CategoryKind.location.rawValue] {
                mapButton(showingMap)
                    .position(x: locationIconX[stretchSelected] ?? pill.midX,
                              y: pill.minY - Self.topPadding - 8 - Self.mapButtonSize / 2)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
    }

    private func mapButton(_ showingMap: Binding<Bool>) -> some View {
        let tint = CategoryKind.location.tint
        return Button {
            showingMap.wrappedValue.toggle()
        } label: {
            Image(systemName: showingMap.wrappedValue ? "list.bullet" : "map.fill")
                .font(.body.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white)
                .frame(width: Self.mapButtonSize, height: Self.mapButtonSize)
                .background(tint, in: .circle)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showingMap.wrappedValue ? "Show as List" : "Show on Map")
    }

    private func chip(_ kind: CategoryKind?, label: String, systemImage: String, tint: Color, stretch: Bool) -> some View {
        let isSelected = selection == kind
        return Button {
            selection = kind
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("filterChips")).midX } action: { x in
                        if kind == .location { locationIconX[stretch] = x }
                    }
                if isSelected {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize()
                }
            }
            .foregroundStyle(isSelected ? .white : tint)
            .padding(.horizontal, isSelected ? 12 : 0)
            .frame(minWidth: Self.chipHeight, maxWidth: isSelected && stretch ? .infinity : nil, minHeight: Self.chipHeight)
            .background(isSelected ? tint : tint.opacity(0.15), in: .capsule)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("filterChips")) } action: { frame in
            if stretch {
                chipFrames[kind?.rawValue ?? "all"] = frame
            } else {
                scrollingChipFrames[kind?.rawValue ?? "all"] = frame
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
