import SwiftUI

extension View {
    /// Pull down past the top of the list to add an item (to `list`, if given). Apply directly to the List.
    func pullToAdd(enabled: Bool, list: ItemList? = nil) -> some View {
        modifier(PullToAdd(enabled: enabled, list: list))
    }
}

private struct PullToAdd: ViewModifier {
    let enabled: Bool
    let list: ItemList?

    @State private var pull: CGFloat = 0
    @State private var isDragging = false
    @State private var addArmed = false
    @State private var showingNewItem = false
    private let addThreshold: CGFloat = 100

    func body(content: Content) -> some View {
        content
            // Only real drags count: layout changes (launch, a sheet closing) can briefly read as overscroll.
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                -(geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, overscroll in
                guard enabled else { return }
                pull = max(0, overscroll)
                if isDragging { addArmed = pull >= addThreshold }
            }
            .background {
                if enabled {
                    ScrollTouchReader { dragging in
                        isDragging = dragging
                        if !dragging {
                            if addArmed { showingNewItem = true }
                            addArmed = false
                        }
                    }
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: addArmed) { _, armed in armed }
            .overlay(alignment: .top) {
                if enabled && isDragging && pull > 4 {
                    NewCardHint(progress: min(pull / addThreshold, 1), armed: addArmed,
                                reveal: max(0, min(pull - 16, 80)))
                        .padding(.top, 8)
                }
            }
            .accessibilityActions {
                if enabled {
                    Button("Add Item") { showingNewItem = true }
                }
            }
            .sheet(isPresented: $showingNewItem) { NewItemView(list: list) }
    }
}

/// A new card edging down from behind the header while the user pulls down.
/// Only its bottom shows at first; it turns solid once releasing will add.
private struct NewCardHint: View {
    let progress: CGFloat
    let armed: Bool
    /// How much of the card has emerged, in points.
    let reveal: CGFloat

    private let cardHeight: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(armed ? Color(.secondarySystemGroupedBackground) : .clear)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.secondary.opacity(armed ? 0 : 0.6 * progress),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(armed ? .primary : .secondary)
                .opacity(progress)
                .scaleEffect(0.6 + 0.4 * progress)
        }
        .frame(height: cardHeight)
        .padding(.horizontal, 16)
        // Show only the emerged bottom of the card, fading out toward the header.
        .frame(height: reveal, alignment: .bottom)
        .clipped()
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.45),
                                   .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .animation(.snappy(duration: 0.15), value: armed)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

