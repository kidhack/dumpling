import SwiftUI

extension ItemCategory {
    var label: String {
        switch self {
        case .event: return "Event"
        case .task: return "Task"
        case .link: return "Link"
        case .idea: return "Idea"
        case .music: return "Music"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .event: return "calendar"
        case .task: return "checklist"
        case .link: return "link"
        case .idea: return "lightbulb"
        case .music: return "music.note"
        case .other: return "square.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .event: return .red
        case .task: return .orange
        case .link: return .blue
        case .idea: return .yellow
        case .music: return .pink
        case .other: return .gray
        }
    }
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
