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

    /// Deeper shades in light mode, from Apple's high-contrast system colors, so icons and white text read on
    /// white (each at least 4.4:1); dark mode keeps the system colors.
    var tint: Color {
        switch self {
        case .event: return Color(light: 0xD70015, dark: 0xFF453A)
        case .task: return Color(light: 0xC93400, dark: 0xFF9F0A)
        case .location: return Color(light: 0x248A3D, dark: 0x30D158)
        case .link: return Color(light: 0x0062CC, dark: 0x0A84FF)
        case .idea: return Color(light: 0xA16207, dark: 0xFFD60A)
        case .music: return Color(light: 0xD30F45, dark: 0xFF375F)
        case .other: return Color(light: 0x6C6C70, dark: 0x98989D)
        }
    }

    /// Map pins: the deep green in both modes, so the pin's white glyph reads on it.
    static let pinTint = Color(rgb: 0x248A3D)

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
