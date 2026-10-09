import SwiftUI

extension ItemCategory {
    var kind: CategoryKind { CategoryKind(rawValue: rawValue) ?? .other }
    var label: String { kind.label }
    var systemImage: String { kind.systemImage }
    var tint: Color { kind.tint }
}

/// The category icon for an item; an hourglass while it waits to be sorted.
struct CategoryIcon: View {
    let item: Item

    var body: some View {
        let category = item.category.flatMap(ItemCategory.init(rawValue:))
        Image(systemName: category?.systemImage ?? "hourglass")
            .font(.title3)
            .foregroundStyle(category?.tint ?? .secondary)
            .frame(width: 28)
            .accessibilityLabel(category?.label ?? "Not sorted yet")
    }
}
