// Minimal stand-in for the SwiftData Item so Sorter.swift compiles as a macOS tool.
final class Item {
    var contentURL: String?; var contentText: String?; var userNote: String?; var quickTag: String?
    init(url: String? = nil, text: String? = nil, note: String? = nil, tag: String? = nil) {
        contentURL = url; contentText = text; userNote = note; quickTag = tag
    }
    var tagLabel: String? { quickTag }
}

import SwiftUI

// The app's light/dark colors use UIKit; the Mac harness only sorts, so any color will do.
extension Color {
    init(light: UInt32, dark: UInt32) { self = .gray }
    init(rgb: UInt32) { self = .gray }
}
