import SwiftUI

/// Categories as the user sees them: label, icon and color. Shared by the share sheet's
/// quick-tag buttons and the app's item list.
enum CategoryKind: String, CaseIterable, Identifiable, Sendable {
    case event, task, location, shopping, media, link, idea

    var id: Self { self }

    var label: String {
        switch self {
        case .event: return "Event"
        case .task: return "Task"
        case .location: return "Location"
        case .shopping: return "Shopping"
        case .media: return "Media"
        case .link: return "Link"
        case .idea: return "Idea"
        }
    }

    /// The category's own icon. Media items show their kind's icon instead (see `MediaKind`).
    var systemImage: String {
        switch self {
        case .event: return "calendar"
        case .task: return "checklist"
        case .location: return "mappin.and.ellipse"
        case .shopping: return "bag"
        case .media: return "play.circle"
        case .link: return "link"
        case .idea: return "lightbulb"
        }
    }

    /// Deeper shades in light mode, from Apple's high-contrast system colors, so icons and white text read on
    /// white (each at least 4.4:1); dark mode keeps the system colors.
    var tint: Color {
        switch self {
        case .event: return Color(light: 0xD70015, dark: 0xFF453A)
        case .task: return Color(light: 0xC93400, dark: 0xFF9F0A)
        case .location: return Color(light: 0x248A3D, dark: 0x30D158)
        case .shopping: return Color(light: 0x8944AB, dark: 0xBF5AF2)
        case .media: return Color(light: 0xD30F45, dark: 0xFF375F)
        case .link: return Color(light: 0x0062CC, dark: 0x0A84FF)
        case .idea: return Color(light: 0xA16207, dark: 0xFFD60A)
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
        case .event, .location, .shopping, .media: return rawValue
        }
    }

    init?(quickTag: String?) {
        // Tags from before Music became Media and Other became Idea.
        switch quickTag {
        case "music": self = .media
        case "other": self = .idea
        default:
            guard let match = Self.allCases.first(where: { $0.quickTag == quickTag }) else { return nil }
            self = match
        }
    }
}

/// What kind of media a Media item is, for its icon and for opening it in Apple's apps.
enum MediaKind: String, CaseIterable, Identifiable, Sendable {
    case music, book, podcast, audiobook, article, blog, video

    var id: Self { self }

    var label: String {
        switch self {
        case .music: return "Music"
        case .book: return "Book"
        case .podcast: return "Podcast"
        case .audiobook: return "Audiobook"
        case .article: return "News Article"
        case .blog: return "Blog"
        case .video: return "Video"
        }
    }

    var systemImage: String {
        switch self {
        case .music: return "music.note"
        case .book: return "book.closed"
        case .podcast: return "mic"
        case .audiobook: return "headphones"
        case .article: return "newspaper"
        case .blog: return "doc.richtext"
        case .video: return "play.rectangle"
        }
    }

    /// The Apple app this kind opens in, if any.
    var appleApp: String? {
        switch self {
        case .music: return "Apple Music"
        case .book, .audiobook: return "Apple Books"
        case .podcast: return "Apple Podcasts"
        case .article, .blog, .video: return nil
        }
    }
}
