import SwiftUI

extension ItemCategory {
    var kind: CategoryKind { CategoryKind(rawValue: rawValue) ?? .idea }
    var label: String { kind.label }
    var systemImage: String { kind.systemImage }
    var tint: Color { kind.tint }
}

extension Item {
    /// The category, reading ones saved before Music became Media and Other became Idea.
    var itemCategory: ItemCategory? { ItemCategory(stored: category) }

    var media: MediaKind? {
        itemCategory == .media ? mediaKind.flatMap(MediaKind.init(rawValue:)) : nil
    }

    /// The category's icon, or for media its kind's (a note for music, a book, a mic for podcasts...).
    var iconName: String? { media?.systemImage ?? itemCategory?.systemImage }
}

/// The category icon for an item; an hourglass while it waits to be sorted.
struct CategoryIcon: View {
    let item: Item

    var body: some View {
        let category = item.itemCategory
        Image(systemName: item.iconName ?? "hourglass")
            .font(.title3)
            .foregroundStyle(category?.tint ?? .secondary)
            // Fixed height so tall symbols (the map pin) don't make some cards taller than others.
            .frame(width: 28, height: 22)
            .accessibilityLabel(item.media?.label ?? category?.label ?? "Processing")
    }
}
