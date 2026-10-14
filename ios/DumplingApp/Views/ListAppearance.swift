import SwiftUI

/// List colors, like Reminders.
enum ListColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown
    var id: Self { self }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        }
    }
}

/// 132 list icons (22 full rows of 6). Every name was checked against the SF Symbols catalog
/// (all available since iOS 18 or earlier).
enum ListSymbols {
    static let defaultSymbol = "list.bullet"

    static let all: [String] = [
        // General
        "list.bullet", "checklist", "list.star", "star.fill", "heart.fill", "bookmark.fill", "flag.fill", "tag.fill",
        "pin.fill", "link",
        // Travel and places
        "airplane", "car.fill", "tram.fill", "bus.fill", "ferry.fill", "sailboat.fill", "bicycle", "figure.walk",
        "suitcase.fill", "bed.double.fill", "map.fill", "map.circle.fill", "mappin.and.ellipse", "signpost.right.fill",
        "binoculars.fill", "globe.americas.fill", "mountain.2.fill", "beach.umbrella.fill", "tent.fill", "house.fill",
        "building.2.fill", "building.columns.fill",
        // Food and drink
        "fork.knife", "cup.and.saucer.fill", "cup.and.heat.waves.fill", "mug.fill", "wineglass.fill",
        "takeoutbag.and.cup.and.straw.fill", "frying.pan.fill", "birthday.cake.fill", "carrot.fill", "fish.fill",
        "popcorn.fill",
        // Shopping
        "cart.fill", "bag.fill", "basket.fill", "gift.fill", "tshirt.fill", "creditcard.fill", "dollarsign.circle.fill",
        "shippingbox.fill", "storefront.fill",
        // Music, shows and events
        "music.note", "music.quarternote.3", "headphones", "guitars.fill", "pianokeys", "tv.fill", "film.fill",
        "theatermasks.fill", "ticket.fill", "party.popper.fill", "balloon.fill", "music.note.house.fill", "fireworks",
        // Reading and learning
        "book.fill", "text.book.closed.fill", "books.vertical.fill", "newspaper.fill", "graduationcap.fill",
        "pencil", "paintbrush.fill", "paintpalette.fill", "camera.fill", "photo.fill",
        // Ideas and play
        "lightbulb.fill", "brain.head.profile", "sparkles", "wand.and.stars", "puzzlepiece.fill",
        "gamecontroller.fill",
        // Sports and activities
        "sportscourt.fill", "soccerball", "basketball.fill", "tennisball.fill", "figure.run", "figure.hiking",
        "figure.climbing", "figure.surfing", "figure.skiing.downhill", "figure.socialdance", "figure.yoga",
        "dumbbell.fill", "trophy.fill",
        // Health, nature and pets
        "heart.text.square.fill", "cross.case.fill", "pills.fill", "leaf.fill", "tree.fill", "pawprint.fill",
        "dog.fill", "cat.fill",
        // Weather
        "sun.max.fill", "moon.fill", "cloud.fill", "snowflake", "flame.fill", "drop.fill", "bolt.fill",
        "umbrella.fill",
        // Time and reminders
        "calendar", "calendar.badge.clock", "clock.fill", "alarm.fill", "hourglass", "bell.fill", "envelope.fill",
        "phone.fill", "message.fill",
        // People
        "person.fill", "person.2.fill", "person.3.fill", "figure.2.and.child.holdinghands", "stroller.fill",
        "heart.circle.fill", "hand.thumbsup.fill", "face.smiling.fill", "crown.fill",
        // Work and home
        "briefcase.fill", "folder.fill", "laptopcomputer", "target",
    ]
}

extension ItemList {
    var listColor: ListColor { colorName.flatMap(ListColor.init(rawValue:)) ?? .teal }
    var symbol: String { symbolName ?? ListSymbols.defaultSymbol }
}

/// A list's icon: its symbol in white on a circle of its color, like Reminders.
struct ListIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28

    init(list: ItemList, size: CGFloat = 28) {
        self.symbol = list.symbol
        self.color = list.listColor.color
        self.size = size
    }

    init(symbol: String, color: Color, size: CGFloat = 28) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: .circle)
            .accessibilityHidden(true)
    }
}
