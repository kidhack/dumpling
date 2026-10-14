import Foundation

/// A link that opens a song, book, podcast or audiobook in Apple's apps. Apple links are used as they are;
/// for anything else (Spotify, Goodreads, a review) the title is looked up in Apple's public catalog
/// (the iTunes Search API, no account needed).
enum AppleMediaLink {
    private static let appleHosts: Set<String> = ["music.apple.com", "podcasts.apple.com", "books.apple.com"]

    static func find(title: String, kind: MediaKind, link: String?) async -> URL? {
        if let url = link.flatMap(URL.init(string:)), let host = url.host()?.lowercased(), appleHosts.contains(host) {
            return url
        }
        let media: String
        switch kind {
        case .music: media = "music"
        case .book: media = "ebook"
        case .audiobook: media = "audiobook"
        case .podcast: media = "podcast"
        case .article, .blog, .video: return nil
        }
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: title),
            URLQueryItem(name: "media", value: media),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "US"),
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(SearchResponse.self, from: data).results.first
        else { return nil }
        return (result.trackViewUrl ?? result.collectionViewUrl ?? result.artistViewUrl).flatMap(URL.init(string:))
    }

    private struct SearchResponse: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let trackViewUrl: String?
        let collectionViewUrl: String?
        let artistViewUrl: String?
    }
}
