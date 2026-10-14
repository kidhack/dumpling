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

/// 128 list icons. Every name was checked against the SF Symbols catalog (all available since iOS 18 or earlier).
enum ListSymbols {
    static let defaultSymbol = "list.bullet"

    static let all: [String] = [
        "list.bullet", "checklist", "star.fill", "heart.fill", "bookmark.fill", "flag.fill", "tag.fill", "pin.fill",
        "airplane", "car.fill", "tram.fill", "bus.fill", "ferry.fill", "bicycle", "figure.walk", "suitcase.fill",
        "map.fill", "globe.americas.fill", "mountain.2.fill", "beach.umbrella.fill", "tent.fill", "house.fill",
        "building.2.fill", "building.columns.fill",
        "fork.knife", "cup.and.saucer.fill", "wineglass.fill", "mug.fill", "takeoutbag.and.cup.and.straw.fill",
        "birthday.cake.fill", "carrot.fill", "fish.fill",
        "cart.fill", "bag.fill", "basket.fill", "gift.fill", "creditcard.fill", "dollarsign.circle.fill",
        "shippingbox.fill", "storefront.fill",
        "music.note", "headphones", "guitars.fill", "pianokeys", "music.mic", "tv.fill", "film.fill",
        "theatermasks.fill",
        "book.fill", "books.vertical.fill", "newspaper.fill", "graduationcap.fill", "pencil", "paintbrush.fill",
        "paintpalette.fill", "camera.fill",
        "photo.fill", "lightbulb.fill", "brain.head.profile", "sparkles", "wand.and.stars", "puzzlepiece.fill",
        "gamecontroller.fill", "dice.fill",
        "sportscourt.fill", "soccerball", "basketball.fill", "tennisball.fill", "figure.run", "figure.hiking",
        "figure.yoga", "dumbbell.fill",
        "heart.text.square.fill", "cross.case.fill", "pills.fill", "leaf.fill", "tree.fill", "pawprint.fill",
        "dog.fill", "cat.fill",
        "sun.max.fill", "moon.fill", "cloud.fill", "snowflake", "flame.fill", "drop.fill", "bolt.fill",
        "umbrella.fill",
        "calendar", "clock.fill", "alarm.fill", "hourglass", "bell.fill", "envelope.fill", "phone.fill",
        "message.fill",
        "person.fill", "person.2.fill", "person.3.fill", "figure.2.and.child.holdinghands", "heart.circle.fill",
        "hand.thumbsup.fill", "face.smiling.fill", "crown.fill",
        "briefcase.fill", "folder.fill", "doc.text.fill", "paperclip", "laptopcomputer", "desktopcomputer",
        "iphone", "wrench.and.screwdriver.fill",
        "hammer.fill", "key.fill", "lock.fill", "shield.fill", "trophy.fill", "medal.fill", "rosette", "target",
        "ticket.fill", "party.popper.fill", "balloon.fill", "music.note.house.fill", "popcorn.fill", "fireworks",
        "sailboat.fill", "stroller.fill",
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
