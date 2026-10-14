import SwiftUI

extension View {
    /// A row without a card behind it, divided from the next by a faint line. The list keeps its margin from the
    /// screen edges; with no card, the row's own side padding goes, so its icon lines up with the title.
    func plainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(.horizontal, 4)
            .listRowSeparatorTint(Color(.separator).opacity(0.5))
            // Only lines between rows: not the group's top and bottom edges, which showed above the first row.
            .listSectionSeparator(.hidden)
    }

    /// The list style shared by every items screen: spacing between groups, and the soft edge under the bars
    /// everywhere (left to itself, iOS sometimes picked the hard edge, a dark band behind the bottom bar).
    func cardList() -> some View {
        listSectionSpacing(10)
            .scrollEdgeEffectStyle(.soft, for: .all)
    }
}
