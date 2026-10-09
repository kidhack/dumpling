import SwiftUI

/// Categories as the user sees them: label, icon and color. Shared by the share sheet's
/// quick-tag buttons and the app's item list.
enum CategoryKind: String, CaseIterable, Identifiable, Sendable {
    case event, task, location, link, idea, music, other

    var id: Self { self }

    var label: String {
        switch self {
        case .event: return "Event"
        case .task: return "Task"
        case .location: return "Location"
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
        case .location: return "mappin.and.ellipse"
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
        case .location: return .green
        case .link: return .blue
        case .idea: return .yellow
        case .music: return .pink
        case .other: return .gray
        }
    }

    /// The value saved as an item's quick tag. Older items used these names, so they're kept.
    var quickTag: String {
        switch self {
        case .task: return "reminder"
        case .link: return "link_save"
        case .idea: return "software_idea"
        case .event, .location, .music, .other: return rawValue
        }
    }

    init?(quickTag: String?) {
        guard let match = Self.allCases.first(where: { $0.quickTag == quickTag }) else { return nil }
        self = match
    }
}
