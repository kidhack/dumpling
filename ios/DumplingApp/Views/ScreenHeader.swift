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
    /// The card list style shared by every items screen: spacing between cards, and the soft edge under the
    /// bars everywhere (left to itself, iOS sometimes picked the hard edge, a dark band behind the bottom bar).
    func cardList() -> some View {
        listSectionSpacing(10)
            .scrollEdgeEffectStyle(.soft, for: .all)
    }

    /// Pins `header` above a scrolling list, with the system's soft edge effect beneath it.
    func screenHeader<Header: View>(@ViewBuilder _ header: () -> Header) -> some View {
        modifier(ScreenHeaderModifier(header: header()))
    }
}

private struct ScreenHeaderModifier<Header: View>: ViewModifier {
    let header: Header

    func body(content: Content) -> some View {
        // A bar, not an inset, so content scrolling under it gets the system's soft edge effect.
        content
            .safeAreaBar(edge: .top, spacing: 0) {
                header.padding(.bottom, 4)
            }
    }
}
