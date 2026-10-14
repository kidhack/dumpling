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
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .frame(height: 44)
    }
}

extension View {
    /// Bars use the system's scroll edge effect (`safeAreaBar`), which a map doesn't get since it isn't a
    /// scroll view. Over the map, this frosts it beneath a bottom bar instead, fading in from above the bar.
    func mapFrost(_ active: Bool) -> some View {
        background {
            if active {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask {
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: 40)
                            Color.black
                        }
                    }
                    .padding(.top, -40)
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.opacity)
            }
        }
    }

    /// Pins `header` above a scrolling list, with the system's soft edge effect beneath it. Over a map
    /// (not a scroll view, so no edge effect) the map is frosted beneath it instead.
    func screenHeader<Header: View>(overMap: Bool = false, @ViewBuilder _ header: () -> Header) -> some View {
        modifier(ScreenHeaderModifier(header: header(), overMap: overMap))
    }
}

private struct ScreenHeaderModifier<Header: View>: ViewModifier {
    let header: Header
    let overMap: Bool

    func body(content: Content) -> some View {
        // A bar, not an inset, so content scrolling under it gets the system's soft edge effect.
        content
            .safeAreaBar(edge: .top, spacing: 0) {
                header
                    .padding(.bottom, 4)
                    .background {
                        if overMap {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .mask {
                                    LinearGradient(stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                                                   startPoint: .top, endPoint: .bottom)
                                }
                                .padding(.bottom, -44)
                                .ignoresSafeArea(edges: .top)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: overMap)
            }
    }
}
