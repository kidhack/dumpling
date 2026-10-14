import SwiftUI

/// The fixed-height header used on every tab and list, so the first card starts at the same height everywhere.
struct ScreenHeader<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 4) {
            leading
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

extension View {
    /// Header titles and text buttons sit on Liquid Glass, like the tab bar.
    func headerGlass(interactive: Bool = true) -> some View {
        padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(.capsule)
            .glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
    }

    /// Header icon buttons: a glass circle.
    func headerGlassCircle() -> some View {
        frame(width: 44, height: 44)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

extension View {
    /// A row without a card behind it, divided from the next by a faint line.
    func plainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparatorTint(Color(.separator).opacity(0.5))
            // Only lines between rows: not the group's top and bottom edges, which showed above the first row.
            .listSectionSeparator(.hidden)
    }

    /// The card list style shared by every items screen: spacing between cards, and the soft edge under the
    /// bars everywhere (left to itself, iOS sometimes picked the hard edge, a dark band behind the bottom bar).
    func cardList() -> some View {
        listSectionSpacing(10)
            .scrollEdgeEffectStyle(.soft, for: .all)
            // Rows are plain now, so the inset a card needed from the screen edges is just empty space. Without
            // it, row icons line up with the header and filter row.
            .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    /// Pins `header` above a scrolling list, with the system's soft edge effect beneath it.
    /// `hidden` takes the bar out entirely (no height), for a screen that shows its header elsewhere, like the map.
    func screenHeader<Header: View>(hidden: Bool = false, @ViewBuilder _ header: () -> Header) -> some View {
        modifier(ScreenHeaderModifier(header: header(), hidden: hidden))
    }
}

enum ScreenHeaderSpacing {
    /// Room between the header controls and the first card. Screens that place the header themselves (the map)
    /// use it too, so the header doesn't move between them.
    static let bottom: CGFloat = 14
}

private struct ScreenHeaderModifier<Header: View>: ViewModifier {
    let header: Header
    let hidden: Bool
    @State private var isScrolled = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > 2
            } action: { _, scrolled in
                // No withAnimation here: it animated the list's top inset mid-bounce, so pulling past the
                // top settled near row 2 and then snapped. Only the backdrop's opacity animates (below).
                isScrolled = scrolled
            }
            // A bar, not an inset, so content scrolling under it gets the system's soft edge effect.
            .safeAreaBar(edge: .top, spacing: 0) {
                if !hidden {
                    header
                        .padding(.bottom, ScreenHeaderSpacing.bottom)
                        .background { backdrop }
                }
            }
    }

    /// Like Reminders and Notes: once the list scrolls, what's behind the header blurs and dims, solid behind
    /// the buttons and fading out just below them. At rest nothing covers the first card.
    private var backdrop: some View {
        let mask = LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6),
                                          .init(color: .clear, location: 1)],
                                  startPoint: .top, endPoint: .bottom)
        return ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color(.systemGroupedBackground).opacity(0.55)
        }
        .mask(mask)
        .padding(.bottom, -16)
        .ignoresSafeArea(edges: .top)
        .opacity(isScrolled ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: isScrolled)
        .allowsHitTesting(false)
    }
}
