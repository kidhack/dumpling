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
    /// Pins `header` above a scrolling list. Cards fade out beneath it once the list is scrolled;
    /// at rest nothing dims the first card.
    func screenHeader<Header: View>(@ViewBuilder _ header: () -> Header) -> some View {
        modifier(ScreenHeaderModifier(header: header()))
    }
}

private struct ScreenHeaderModifier<Header: View>: ViewModifier {
    let header: Header
    @State private var isScrolled = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > 2
            } action: { _, scrolled in
                withAnimation(.easeOut(duration: 0.2)) { isScrolled = scrolled }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .padding(.bottom, 4)
                    .background {
                        LinearGradient(stops: [.init(color: Color(.systemGroupedBackground), location: 0.5),
                                               .init(color: Color(.systemGroupedBackground).opacity(0), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .padding(.bottom, -44)
                            .ignoresSafeArea(edges: .top)
                            .opacity(isScrolled ? 1 : 0)
                    }
            }
    }
}
