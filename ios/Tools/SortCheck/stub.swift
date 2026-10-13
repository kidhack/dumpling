// Minimal stand-in for the SwiftData Item so Sorter.swift compiles as a macOS tool.
final class Item {
    var contentURL: String?; var contentText: String?; var userNote: String?; var quickTag: String?
    init(url: String? = nil, text: String? = nil, note: String? = nil, tag: String? = nil) {
        contentURL = url; contentText = text; userNote = note; quickTag = tag
    }
    var tagLabel: String? { quickTag }
}
