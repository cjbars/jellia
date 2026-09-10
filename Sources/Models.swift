import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case playlists
    case artists
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playlists: return "Playlists"
        case .artists: return "Artists"
        case .favorites: return "Favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .playlists: return AppIcon.playlists
        case .artists: return AppIcon.artists
        case .favorites: return AppIcon.favoritesFilled
        }
    }
}

enum LibraryRoute: Hashable {
    case search
    case playlist(Playlist)
    case artist(Artist)
    case album(Album)

    var itemID: String? {
        switch self {
        case .search:
            return nil
        case .playlist(let playlist):
            return playlist.itemID
        case .artist(let artist):
            return artist.itemID
        case .album(let album):
            return album.itemID
        }
    }
}

enum PlaybackRepeatMode: String, Codable {
    case off
    case all
    case one
}

enum DateDisplayFormat: String, CaseIterable, Identifiable {
    case year
    case monthAndYear
    case fullDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .year: return "Year only"
        case .monthAndYear: return "Month and year"
        case .fullDate: return "Full date"
        }
    }

    func string(from iso8601: String?, fallbackYear: Int?) -> String? {
        guard let iso8601,
              let date = Self.parse(iso8601)
        else {
            return fallbackYear.map(String.init)
        }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = Calendar.current
        formatter.dateFormat = switch self {
        case .year: "yyyy"
        case .monthAndYear: "MMM yyyy"
        case .fullDate: "d MMMM yyyy"
        }
        return formatter.string(from: date)
    }

    private static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
            ?? {
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: value)
            }()
    }
}

enum PlaybackQueueState {
    static func currentIndex(in queue: [Track], for currentTrack: Track) -> Int? {
        guard currentTrack.itemID != nil else { return nil }
        return queue.firstIndex { $0.matches(currentTrack) }
    }

    static func nextIndex(in queue: [Track], from index: Int, wrapping: Bool) -> Int? {
        guard !queue.isEmpty, queue.indices.contains(index) else { return nil }
        if index < queue.count - 1 { return index + 1 }
        return wrapping ? 0 : nil
    }

    static func previousIndex(in queue: [Track], from index: Int, wrapping: Bool) -> Int? {
        guard !queue.isEmpty, queue.indices.contains(index) else { return nil }
        if index > 0 { return index - 1 }
        return wrapping ? queue.count - 1 : nil
    }
}

enum ArtworkReference {
    static func itemID(for track: Track) -> String? {
        track.albumID ?? track.parentID ?? track.itemID
    }

    static func cacheKey(itemID: String, maxWidth: Int) -> String {
        "\(itemID)-w\(min(max(maxWidth, 64), 1_024))"
    }
}

struct Track: Identifiable, Codable, Hashable {
    let id: String
    var itemID: String?
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var isFavorite: Bool
    var mediaSourceID: String?
    var playSessionID: String?
    var albumID: String? = nil
    var parentID: String? = nil
    var trackNumber: Int? = nil
    var discNumber: Int? = nil
    var artistID: String? = nil

    var durationText: String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func albumPositionText(showDisc: Bool) -> String {
        guard let trackNumber else { return "-" }
        if showDisc, let discNumber {
            return "\(discNumber).\(trackNumber)"
        }
        return String(trackNumber)
    }

    static let empty = Track(
        id: "empty-track",
        itemID: nil,
        title: "Nothing Playing",
        artist: "",
        album: "",
        duration: 0,
        isFavorite: false
    )

    func matches(_ other: Track) -> Bool {
        guard let itemID, let otherItemID = other.itemID else { return false }
        return itemID == otherItemID
    }

    func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let normalized = query.lowercased()
        return title.lowercased().contains(normalized)
            || artist.lowercased().contains(normalized)
            || album.lowercased().contains(normalized)
    }
}

struct Playlist: Identifiable, Codable, Hashable {
    let id: String
    var itemID: String?
    var name: String
    var trackCount: Int
    var durationText: String

    func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return name.lowercased().contains(query.lowercased())
    }
}

struct Artist: Identifiable, Codable, Hashable {
    let id: String
    var itemID: String?
    var name: String
    var genre: String
    var songCount: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case itemID
        case name
        case genre
        case songCount = "trackCount"
    }

    func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let normalized = query.lowercased()
        return name.lowercased().contains(normalized) || genre.lowercased().contains(normalized)
    }

    func matchesIdentity(_ other: Artist) -> Bool {
        if let itemID, let otherItemID = other.itemID {
            return itemID == otherItemID
        }
        return id == other.id
    }
}

struct Album: Identifiable, Codable, Hashable {
    let id: String
    var itemID: String?
    var title: String
    var artist: String
    var year: Int?
    var releaseDate: String? = nil
    var dateCreated: String? = nil
    var genres: [String] = []
    var overview: String? = nil
    var trackCount: Int
    var durationText: String
    var artistID: String? = nil

    func releaseText(format: DateDisplayFormat = .year) -> String? {
        format.string(from: releaseDate, fallbackYear: year)
    }

    var releaseYearText: String? {
        releaseText(format: .year)
    }

    var subtitle: String {
        var parts = [artist]
        if let releaseText = releaseText(format: .year) {
            parts.append(releaseText)
        }
        if trackCount > 0 {
            parts.append("\(trackCount) tracks")
        }
        return parts.joined(separator: " - ")
    }

    func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let normalized = query.lowercased()
        return title.lowercased().contains(normalized) || artist.lowercased().contains(normalized)
    }
}

struct LibrarySnapshot {
    var playlists: [Playlist]
    var artists: [Artist]
    var favoriteTracks: [Track]
}

enum LibraryProjection {
    static func artists(_ artists: [Artist], applying counts: [String: Int]) -> [Artist] {
        artists.map { artist in
            guard let itemID = artist.itemID, let count = counts[itemID] else { return artist }
            var resolved = artist
            resolved.songCount = count
            return resolved
        }
    }

    static func artistIndexByID(_ artists: [Artist]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: artists.enumerated().compactMap { index, artist in
            guard let itemID = artist.itemID else { return nil }
            return (itemID, index)
        })
    }
}

struct SearchResults {
    var tracks: [Track] = []
    var artists: [Artist] = []
    var albums: [Album] = []
    var playlists: [Playlist] = []

    var isEmpty: Bool {
        tracks.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty
    }
}

struct JellyfinSession: Codable, Sendable {
    var serverURL: URL
    var userID: String
    var userName: String
    var accessToken: String
    var deviceID: String
    /// Сведения о сервере; отсутствуют у сессий, сохранённых прежними версиями.
    var server: JellyfinServerInfo?
}

struct PlaybackContext {
    var streamURL: URL
    var itemID: String
    var playSessionID: String?
    var mediaSourceID: String?
    var duration: TimeInterval?
}
